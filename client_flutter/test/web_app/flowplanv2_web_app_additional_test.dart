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
  testWidgets('creates tasks and creates then edits events from the web shell',
      (tester) async {
    final harness = await _pumpWebApp(tester);

    await _openShellDestination(tester, AppKeys.webShellTasks);
    await tester.tap(find.byKey(AppKeys.webTasksCreateButton));
    await _pumpFrames(tester, 4);
    await _fillDialogFields(tester, [
      'Additional task',
      'in_progress',
      '2026-06-10T18:00:00.000',
      'Desk',
      'Created by widget flow',
    ]);
    await _tapDialogSave(tester);

    expect(harness.api.postPaths, contains('/web/tasks'));
    expect(harness.api.postBodies['/web/tasks']!.single, {
      'title': 'Additional task',
      'status': 'in_progress',
      'dueAt': '2026-06-10T18:00:00.000',
      'location': 'Desk',
      'notes': 'Created by widget flow',
    });

    await _openShellDestination(tester, AppKeys.webShellEvents);
    await _tapFilledButtonIcon(tester, Icons.add);
    await _fillDialogFields(tester, [
      'Additional event',
      '2026-06-10T09:00:00.000',
      '2026-06-10T10:00:00.000',
      'Room 9',
      'tentative',
      'Created event notes',
    ]);
    await _tapDialogSave(tester);

    expect(harness.api.postPaths, contains('/web/events'));
    expect(harness.api.postBodies['/web/events']!.single['title'],
        'Additional event');
    expect(harness.api.postBodies['/web/events']!.single['notes'],
        'Created event notes');

    await _tapIcon(tester, Icons.table_rows_outlined);
    await tester.tap(find.byType(TextButton).last);
    await _pumpFrames(tester, 4);
    await _fillDialogFields(tester, [
      'Edited planning sync',
      harness.api.todayAt(hour: 11),
      harness.api.todayAt(hour: 12),
      'Room 10',
      'confirmed',
      'Edited event notes',
    ]);
    await _tapDialogSave(tester);

    expect(harness.api.patchPaths, contains('/web/events/event-1'));
    expect(harness.api.patchBodies['/web/events/event-1']!.single['title'],
        'Edited planning sync');
    expect(harness.api.patchBodies['/web/events/event-1']!.single['notes'],
        'Edited event notes');
  });

  testWidgets('settings saves browser identity and login refreshes connection',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellSettings);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'http://localhost:3300/api/');
    await tester.enterText(fields.at(1), 'settings-user');
    await _tapFilledButtonIcon(tester, Icons.save_outlined);

    expect(harness.store.baseUrl, 'http://localhost:3300/api');
    expect(harness.store.userId, 'settings-user');

    await _tapOutlinedButtonIcon(tester, Icons.login);

    expect(harness.api.postPaths, contains('/auth/login'));
    expect(harness.api.postBodies['/auth/login']!.single['userId'],
        'settings-user');
    expect(harness.store.userId, 'logged-in-user');
    expect(harness.store.accessToken, 'access-token');
    expect(harness.store.refreshToken, 'refresh-token');
    expect(
      harness.api.postPaths,
      contains('/devices/web-device/heartbeat'),
    );
  });
}

Finder _dialogFields() {
  return find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );
}

Future<void> _fillDialogFields(
  WidgetTester tester,
  List<String> values,
) async {
  final fields = _dialogFields();
  expect(fields, findsNWidgets(values.length));
  for (var i = 0; i < values.length; i += 1) {
    await tester.enterText(fields.at(i), values[i]);
  }
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

Future<void> _tapFilledButtonIcon(
  WidgetTester tester,
  IconData icon, {
  int index = 0,
}) async {
  final button = find.widgetWithIcon(FilledButton, icon).at(index);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _pumpFrames(tester, 8);
}

Future<void> _tapOutlinedButtonIcon(WidgetTester tester, IconData icon) async {
  final button = find.widgetWithIcon(OutlinedButton, icon).first;
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

Future<_WebAppHarness> _pumpWebApp(WidgetTester tester) async {
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
  final api = _AdditionalWebApiClient(store);

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
  final _AdditionalWebApiClient api;
}

class _AdditionalWebApiClient extends WebApiClient {
  _AdditionalWebApiClient(super.store)
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

  late final DateTime today = DateTime.now();

  String todayAt({required int hour}) {
    return DateTime(today.year, today.month, today.day, hour).toIso8601String();
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
        return {
          'items': [
            {
              'id': 'task-1',
              'title': 'Existing task',
              'status': 'todo',
              'dueAt': todayAt(hour: 17),
              'location': 'Desk',
              'payload': {'notes': 'Existing notes'},
            },
          ],
        };
      case '/web/events':
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
                'description': 'Payload note',
              },
            },
          ],
        };
      case '/client/settings':
        return {
          'settings': [
            {
              'key': 'web.coverage',
              'scope': 'user',
              'version': 1,
              'updatedAt': '2026-06-10T04:00:00.000Z',
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
      case '/web/tasks':
        return {
          'task': {'id': 'created-task', ...body},
        };
      case '/web/events':
        return {
          'event': {'id': 'created-event', ...body},
        };
      case '/auth/login':
        return {
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'user': {'id': 'logged-in-user'},
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
    return {'ok': true};
  }
}
