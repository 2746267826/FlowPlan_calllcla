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
  testWidgets('dashboard renders today panels and reloads when returning home',
      (tester) async {
    final harness = await _pumpWebApp(tester);

    expect(harness.api.getPaths, contains('/web/dashboard'));
    expect(find.text('Focus build'), findsOneWidget);
    expect(find.textContaining('Ship dashboard coverage'), findsOneWidget);
    expect(find.textContaining('Client sync'), findsOneWidget);
    expect(find.text('Reviewed morning metrics'), findsOneWidget);

    final dashboardLoads =
        harness.api.getPaths.where((path) => path == '/web/dashboard').length;
    await _openShellDestination(tester, AppKeys.webShellTasks);
    await _openShellDestination(tester, AppKeys.webShellToday);

    expect(
      harness.api.getPaths.where((path) => path == '/web/dashboard').length,
      dashboardLoads + 1,
    );
  });

  testWidgets('events page searches, creates, and edits calendar entries',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellEvents);

    expect(find.text('Planning sync'), findsOneWidget);
    expect(harness.api.getPaths, contains('/web/events'));

    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'retro');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester, 6);
    expect(harness.api.lastGetQuery('/web/events')['q'], 'retro');

    await _tapIcon(tester, Icons.add);
    final createFields = _dialogFields();
    await tester.enterText(createFields.at(0), 'Client retro');
    await tester.enterText(createFields.at(1), harness.api.todayAt(hour: 14));
    await tester.enterText(createFields.at(2), harness.api.todayAt(hour: 15));
    await tester.enterText(createFields.at(3), 'Room 9');
    await tester.enterText(createFields.at(4), 'confirmed');
    await tester.enterText(createFields.at(5), 'Retrospective notes');
    await _tapDialogSave(tester);

    expect(harness.api.postPaths, contains('/web/events'));
    expect(harness.api.createdEvents.single['title'], 'Client retro');
    expect(harness.api.createdEvents.single['location'], 'Room 9');

    await tester.enterText(searchField, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester, 6);
    await _tapText(tester, 'Planning sync');
    final editFields = _dialogFields();
    await tester.enterText(editFields.at(0), 'Planning sync edited');
    await tester.enterText(editFields.at(5), 'Updated event notes');
    await _tapDialogSave(tester);

    expect(harness.api.patchPaths, contains('/web/events/event-1'));
    expect(harness.api.events.first['title'], 'Planning sync edited');
    expect(harness.api.events.first['notes'], 'Updated event notes');
  });

  testWidgets('reports page runs generation and item actions', (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellReports);

    expect(find.textContaining('Daily draft'), findsOneWidget);
    expect(find.textContaining('Daily diary'), findsOneWidget);

    await _tapIcon(tester, Icons.auto_awesome);
    expect(harness.api.postPaths, contains('/reports/generate'));

    await _tapIcon(tester, Icons.edit_note);
    expect(harness.api.postPaths, contains('/diary/generate'));

    await _tapReportAction(tester, 0);
    expect(harness.api.getPaths, contains('/reports/report-1'));
    expect(find.text('Detail markdown'), findsOneWidget);
    await _closeDialog(tester);

    await _tapReportAction(tester, 1);
    final editFields = _dialogFields();
    await tester.enterText(editFields.at(0), 'Daily draft edited');
    await tester.enterText(editFields.at(1), 'Edited markdown');
    await tester.enterText(editFields.at(2), 'Keep the customer proof');
    await _tapDialogSave(tester);
    expect(harness.api.patchPaths, contains('/reports/report-1'));
    expect(harness.api.reports.single['title'], 'Daily draft edited');
    expect(harness.api.reports.single['contentMarkdown'], 'Edited markdown');

    await _tapReportAction(tester, 2);
    expect(harness.api.postPaths, contains('/reports/report-1/confirm'));

    await _tapReportAction(tester, 3);
    expect(harness.api.postPaths, contains('/reports/report-1/polish'));

    await _tapReportAction(tester, 4);
    expect(harness.api.postPaths, contains('/reports/report-1/push'));

    await _tapReportAction(tester, 5);
    final diaryFields = _dialogFields();
    await tester.enterText(diaryFields.at(0), 'Daily diary edited');
    await tester.enterText(diaryFields.at(1), 'Diary markdown edited');
    await _tapDialogSave(tester);
    expect(harness.api.patchPaths, contains('/diary/diary-1'));

    await _tapIcon(tester, Icons.cloud_outlined);
    final weatherFields = _dialogFields();
    await tester.enterText(weatherFields.at(0), 'Shanghai');
    await tester.enterText(weatherFields.at(1), '31.2304');
    await tester.enterText(weatherFields.at(2), '121.4737');
    await tester.enterText(weatherFields.at(3), 'Asia/Shanghai');
    await _tapDialogSave(tester);
    expect(harness.api.postPaths, contains('/weather/locations'));
    expect(harness.api.postPaths,
        contains('/weather/locations/weather-1/refresh'));

    await _tapIcon(tester, Icons.send_outlined);
    final pushFields = _dialogFields();
    await tester.enterText(pushFields.at(0), 'webhook');
    await tester.enterText(pushFields.at(1), 'Ops webhook');
    await tester.enterText(pushFields.at(2), 'https://example.test/hook');
    await _tapDialogSave(tester);
    expect(harness.api.postPaths, contains('/push/channels'));

    await _tapTextButtonByText(tester, 'failed');
    expect(
        harness.api.postPaths, contains('/push/deliveries/delivery-1/retry'));
  });

  testWidgets('settings page saves local values, logs in, and requests notices',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellSettings);

    expect(find.text('remote.theme'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'http://localhost:4300/api/');
    await tester.enterText(fields.at(1), 'login-user');
    await _tapIcon(tester, Icons.save_outlined);
    expect(harness.store.baseUrl, 'http://localhost:4300/api');
    expect(harness.store.userId, 'login-user');

    await _tapIcon(tester, Icons.login);
    expect(harness.api.postPaths, contains('/auth/login'));
    expect(harness.store.accessToken, 'access-token');
    expect(harness.store.refreshToken, 'refresh-token');
    expect(harness.store.userId, 'server-user');

    await _tapIcon(tester, Icons.notifications_active_outlined);
    expect(find.textContaining('unsupported'), findsOneWidget);
  });

  testWidgets('drive page previews downloads and uploads with browser stubs',
      (tester) async {
    final picker = _FakeFilePicker(
      FilePickerResult([
        PlatformFile(
          name: 'upload.txt',
          size: 11,
          bytes: Uint8List.fromList('hello upload'.codeUnits),
        ),
      ]),
    );
    final harness = await _pumpWebApp(tester, filePicker: picker);
    await _openShellDestination(tester, AppKeys.webShellDrive);

    expect(find.text('Project notes.md'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);

    await _tapIcon(tester, Icons.visibility_outlined);
    expect(
      harness.api.postPaths,
      contains('/files/drive/nodes/file-1/download-request'),
    );
    expect(find.text('hello from drive'), findsOneWidget);
    await _closeDialog(tester);

    await _tapIcon(tester, Icons.download);
    expect(
      harness.api.getPaths,
      contains('/files/download-sessions/download-file-1/range'),
    );

    await _tapIcon(tester, Icons.folder_open);
    expect(
        harness.api.lastGetQuery('/files/drive/nodes')['parentId'], 'folder-1');
    expect(find.text('Nested spec.txt'), findsOneWidget);

    await _tapIcon(tester, Icons.upload_file);
    expect(picker.pickCount, 1);
    expect(harness.api.postPaths, contains('/files/upload-sessions'));
    expect(harness.api.putPaths,
        contains('/files/upload-sessions/upload-1/chunks/0'));
    expect(harness.api.postPaths,
        contains('/files/upload-sessions/upload-1/complete'));
    expect(harness.api.uploadedFiles.single['name'], 'upload.txt');
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

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _pumpFrames(tester, 8);
}

Future<void> _tapTextButtonByText(
    WidgetTester tester, String nearbyText) async {
  await tester.ensureVisible(find.textContaining(nearbyText).first);
  final buttons = find.byType(TextButton);
  await tester.tap(buttons.last);
  await _pumpFrames(tester, 8);
}

Future<void> _tapReportAction(WidgetTester tester, int index) async {
  await tester.ensureVisible(find.textContaining('Daily draft').first);
  final buttons = find.byType(TextButton);
  await tester.tap(buttons.at(index));
  await _pumpFrames(tester, 8);
}

Future<void> _openShellDestination(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await _pumpFrames(tester, 8);
}

Future<_WebAppHarness> _pumpWebApp(
  WidgetTester tester, {
  _FakeFilePicker? filePicker,
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
  final api = _FakeWebApiClient(store);

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
  final _FakeWebApiClient api;
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

class _FakeWebApiClient extends WebApiClient {
  _FakeWebApiClient(super.store);

  final getPaths = <String>[];
  final getQueries = <String, List<Map<String, String?>>>{};
  final postPaths = <String>[];
  final postBodies = <String, List<Map<String, dynamic>>>{};
  final patchPaths = <String>[];
  final patchBodies = <String, List<Map<String, dynamic>>>{};
  final putPaths = <String>[];
  final putBodies = <String, List<Map<String, dynamic>>>{};
  final createdEvents = <Map<String, dynamic>>[];
  final uploadedFiles = <Map<String, dynamic>>[];

  late final DateTime today = DateTime.now();

  late final events = <Map<String, dynamic>>[
    {
      'id': 'event-1',
      'title': 'Planning sync',
      'startAt': todayAt(hour: 10),
      'endAt': todayAt(hour: 11),
      'location': 'Room 3',
      'status': 'confirmed',
      'notes': 'Initial plan',
      'payload': {'isBlock': true},
    },
  ];

  final reports = <Map<String, dynamic>>[
    {
      'id': 'report-1',
      'title': 'Daily draft',
      'reportType': 'daily',
      'status': 'draft',
      'summary': 'Draft summary',
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

  final driveRoots = <Map<String, dynamic>>[
    {
      'id': 'root-1',
      'rootUid': 'web-root',
      'name': 'Server drive',
    },
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
            'current': {
              'title': 'Focus build',
              'startAt': todayAt(hour: 9),
              'endAt': todayAt(hour: 10),
              'location': 'Desk',
              'status': 'active',
            },
            'next': {
              'title': 'Follow-up demo',
              'startAt': todayAt(hour: 13),
              'location': 'Meet',
            },
            'tasks': [
              {
                'id': 'task-1',
                'title': 'Ship dashboard coverage',
                'status': 'todo',
                'dueAt': todayAt(hour: 17),
                'location': 'Remote',
              },
            ],
            'events': [
              {
                'id': 'event-dash',
                'title': 'Client sync',
                'startAt': todayAt(hour: 11),
                'endAt': todayAt(hour: 12),
                'location': 'Room 1',
              },
            ],
            'actualRecords': [
              {
                'id': 'actual-1',
                'title': 'Reviewed morning metrics',
                'startAt': todayAt(hour: 8),
                'endAt': todayAt(hour: 9),
                'status': 'confirmed',
              },
            ],
          },
          'lists': {
            'openTasks': <Map<String, Object?>>[],
            'reminders': [
              {'id': 'reminder-1', 'title': 'Stand up'},
            ],
          },
          'sync': {
            'pendingMutations': 2,
            'openConflicts': 1,
          },
        };
      case '/web/tasks':
        return {
          'items': [
            {'id': 'task-1', 'title': 'Web task', 'status': 'todo'},
          ],
        };
      case '/web/events':
        final q = (query['q'] ?? '').toLowerCase();
        return {
          'items': [
            for (final item in events)
              if (q.isEmpty ||
                  '${item['title']}'.toLowerCase().contains(q) ||
                  '${item['location']}'.toLowerCase().contains(q))
                item,
          ],
        };
      case '/reports':
        return {'reports': reports};
      case '/reports/report-1':
        return {
          'report': {
            ...reports.first,
            'contentMarkdown': 'Detail markdown',
          },
          'entries': [
            {
              'claimType': 'task',
              'title': 'Task proof',
              'body': 'Evidence body',
            },
          ],
          'evidence': [
            {
              'evidenceType': 'activity',
              'sourceType': 'tracker',
              'summary': 'Tracker proof',
            },
          ],
        };
      case '/diary':
        return {'diary': diary};
      case '/weather/locations':
        return {
          'items': [
            {'id': 'weather-1', 'name': 'Shanghai'},
          ],
        };
      case '/weather/summary':
        return {
          'items': [
            {
              'locationName': 'Shanghai',
              'summary': 'Clear',
              'expiresAt': '2026-06-10T08:00:00.000Z',
            },
          ],
        };
      case '/push/channels':
        return {
          'items': [
            {'id': 'channel-1', 'name': 'Ops webhook'},
          ],
        };
      case '/push/deliveries':
        return {
          'items': [
            {
              'id': 'delivery-1',
              'channel': 'Ops webhook',
              'status': 'failed',
              'lastError': 'timeout',
            },
          ],
        };
      case '/client/settings':
        return {
          'settings': [
            {
              'key': 'remote.theme',
              'scope': 'user',
              'version': 3,
              'updatedAt': '2026-06-10T00:00:00.000Z',
            },
          ],
        };
      case '/files/drive/roots':
        return {'roots': driveRoots};
      case '/files/drive/nodes':
        return {
          'nodes': query['parentId'] == 'folder-1' ? folderNodes : rootNodes,
        };
      case '/files/download-sessions/download-file-1/range':
        return _downloadRange('hello from drive');
      case '/files/download-sessions/download-file-2/range':
        return _downloadRange('nested text');
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
      case '/web/events':
        createdEvents.add({
          'id': 'event-created-${createdEvents.length + 1}',
          ...body,
        });
        events.add(createdEvents.last);
        return {'event': createdEvents.last};
      case '/reports/generate':
      case '/diary/generate':
      case '/reports/report-1/confirm':
      case '/reports/report-1/push':
      case '/diary/diary-1/confirm':
      case '/diary/diary-1/polish':
        return {'ok': true};
      case '/reports/report-1/polish':
        return {'ok': true, 'llmApplied': false};
      case '/weather/locations':
        return {
          'location': {'id': 'weather-1', ...body},
        };
      case '/weather/locations/weather-1/refresh':
      case '/push/deliveries/delivery-1/retry':
        return {'ok': true};
      case '/push/channels':
        return {
          'channel': {'id': 'channel-1', ...body},
        };
      case '/auth/login':
        return {
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'user': {'id': 'server-user'},
        };
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
        uploadedFiles.add({
          'id': 'uploaded-1',
          'name': 'upload.txt',
          'nodeType': 'file',
          'availability': 'ready',
          'sizeBytes': 11,
          'mimeType': 'text/plain',
        });
        folderNodes.add(uploadedFiles.last);
        return {'node': uploadedFiles.last};
      case '/files/drive/nodes/file-1/download-request':
      case '/files/drive/nodes/file-2/download-request':
        final nodeId = path.split('/')[4];
        return {
          'ok': true,
          'downloadSession': {
            'sessionId': 'download-$nodeId',
            'totalBytes': nodeId == 'file-1' ? 16 : 11,
            'chunkSize': 64,
          },
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
    switch (path) {
      case '/web/events/event-1':
        events.first.addAll(body);
        return {'event': events.first};
      case '/reports/report-1':
        reports.first.addAll(body);
        return {'report': reports.first};
      case '/diary/diary-1':
        diary.first.addAll(body);
        return {'diary': diary.first};
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
