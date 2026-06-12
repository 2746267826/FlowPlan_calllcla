library;

import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/web_app/flowplanv2_web_app.dart';
import 'package:flowplanv2/web_app/web_api_client.dart';
import 'package:flowplanv2/web_app/web_local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('web app shell navigates and runs task actions with fake API', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'web.server.base_url': 'http://localhost:3202/api',
      'web.user_id': 'web-user',
      'web.device_id': 'web-device',
    });
    final store = await WebLocalStore.load();
    final api = _FakeWebApiClient(store);

    await tester.pumpWidget(
      FlowPlanV2WebApp(
        store: store,
        apiClientFactory: (_) => api,
      ),
    );
    await _pumpFrames(tester, 8);

    expect(find.byKey(AppKeys.webShellToday), findsOneWidget);
    expect(api.getPaths, contains('/web/dashboard'));
    expect(api.postPaths, contains('/devices/web-device/heartbeat'));

    await tester.tap(find.byKey(AppKeys.webShellTasks));
    await _pumpFrames(tester, 8);

    expect(api.getPaths, contains('/web/tasks'));
    expect(find.textContaining('Web task'), findsOneWidget);
    expect(find.byKey(AppKeys.webTasksCreateButton), findsOneWidget);
    expect(find.byKey(AppKeys.webTasksRefreshButton), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.webTasksRefreshButton));
    await _pumpFrames(tester, 4);
    expect(api.getPaths.where((path) => path == '/web/tasks'), hasLength(2));

    await tester.tap(find.byKey(AppKeys.webTasksCreateButton));
    await _pumpFrames(tester, 4);
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(dialogFields, findsWidgets);
    await tester.enterText(dialogFields.first, 'New web task');
    final dialogSaveButtons = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    expect(dialogSaveButtons, findsOneWidget);
    await tester.tap(dialogSaveButtons);
    await _pumpFrames(tester, 8);

    expect(api.postPaths, contains('/web/tasks'));
    expect(api.createdTasks.single['title'], 'New web task');

    await tester.tap(find.byKey(AppKeys.webShellReports));
    await _pumpFrames(tester, 8);
    expect(api.getPaths, contains('/reports'));

    await tester.tap(find.byKey(AppKeys.webShellSettings));
    await _pumpFrames(tester, 8);
    expect(api.getPaths, contains('/client/settings'));

    final bootstrapCallsBeforeRefresh =
        api.getPaths.where((path) => path == '/client/bootstrap').length;
    await tester.tap(find.byKey(AppKeys.webShellRefreshConnection));
    await _pumpFrames(tester, 8);
    expect(
      api.getPaths.where((path) => path == '/client/bootstrap').length,
      bootstrapCallsBeforeRefresh + 1,
    );
  });
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

class _FakeWebApiClient extends WebApiClient {
  _FakeWebApiClient(super.store);

  final getPaths = <String>[];
  final postPaths = <String>[];
  final createdTasks = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String?> query = const {},
  }) async {
    getPaths.add(path);
    switch (path) {
      case '/client/bootstrap':
        return {
          'serverTime': '2026-06-10T00:00:00.000Z',
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
            {'id': 'task-1', 'title': 'Web task', 'status': 'todo'},
            ...createdTasks,
          ],
        };
      case '/reports':
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
    if (path == '/web/tasks') {
      createdTasks.add({
        'id': 'created-${createdTasks.length + 1}',
        ...body,
      });
      return {'task': createdTasks.last};
    }
    if (path.endsWith('/heartbeat')) {
      return {'serverTime': '2026-06-10T00:00:01.000Z'};
    }
    return {'ok': true};
  }
}
