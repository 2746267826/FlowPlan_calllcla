library;

import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/web_app/flowplanv2_web_app.dart';
import 'package:flowplanv2/web_app/web_api_client.dart';
import 'package:flowplanv2/web_app/web_local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('reports and settings page refresh actions reload async data',
      (tester) async {
    final harness = await _pumpWebApp(tester);

    await _openShellDestination(tester, AppKeys.webShellReports);
    final reportLoads =
        harness.api.getPaths.where((path) => path == '/reports').length;

    await _tapPageRefresh(tester);

    expect(
      harness.api.getPaths.where((path) => path == '/reports').length,
      reportLoads + 1,
    );
    expect(
      harness.api.getPaths.where((path) => path == '/push/deliveries').length,
      greaterThanOrEqualTo(2),
    );

    await _openShellDestination(tester, AppKeys.webShellSettings);
    final settingsLoads =
        harness.api.getPaths.where((path) => path == '/client/settings').length;

    await _tapPageRefresh(tester);

    expect(
      harness.api.getPaths.where((path) => path == '/client/settings').length,
      settingsLoads + 1,
    );
  });
}

Future<void> _tapPageRefresh(WidgetTester tester) async {
  final finder = find.byTooltip('Refresh');
  expect(finder, findsOneWidget);
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
  final api = _Gap5WebApiClient(store);

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
  final _Gap5WebApiClient api;
}

class _Gap5WebApiClient extends WebApiClient {
  _Gap5WebApiClient(super.store);

  final getPaths = <String>[];
  final postPaths = <String>[];

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String?> query = const {},
  }) async {
    getPaths.add(path);
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
      case '/web/events':
        return {'items': <Map<String, Object?>>[]};
      case '/reports':
        return {
          'reports': [
            {
              'id': 'report-gap5',
              'title': 'Gap5 report',
              'reportType': 'daily',
              'status': 'draft',
              'contentMarkdown': 'Report body',
            },
          ],
        };
      case '/diary':
        return {
          'diary': [
            {
              'id': 'diary-gap5',
              'title': 'Gap5 diary',
              'entryDate': '2026-06-10',
              'status': 'draft',
              'contentMarkdown': 'Diary body',
            },
          ],
        };
      case '/weather/locations':
        return {
          'items': [
            {'id': 'weather-gap5', 'name': 'Shanghai'},
          ],
        };
      case '/weather/summary':
        return {
          'items': [
            {
              'locationName': 'Shanghai',
              'summary': 'clear',
              'expiresAt': '2026-06-10T12:00:00.000Z',
            },
          ],
        };
      case '/push/channels':
        return {
          'items': [
            {'id': 'channel-gap5', 'name': 'alerts'},
          ],
        };
      case '/push/deliveries':
        return {
          'items': [
            {
              'id': 'delivery-gap5',
              'channel': 'alerts',
              'status': 'sent',
              'lastError': '',
            },
          ],
        };
      case '/client/settings':
        return {
          'settings': [
            {
              'key': 'remote.gap5',
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
    if (path.endsWith('/heartbeat')) {
      return {'serverTime': '2026-06-10T04:00:01.000Z'};
    }
    return {'ok': true};
  }
}
