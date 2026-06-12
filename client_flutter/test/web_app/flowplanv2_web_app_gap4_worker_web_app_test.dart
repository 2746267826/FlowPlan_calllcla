library;

import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/web_app/flowplanv2_web_app.dart';
import 'package:flowplanv2/web_app/web_api_client.dart';
import 'package:flowplanv2/web_app/web_local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('reports render server tables and retry failed delivery',
      (tester) async {
    final harness = await _pumpWebApp(tester);

    await _openShellDestination(tester, AppKeys.webShellReports);

    expect(
      harness.api.getPaths,
      containsAll([
        '/reports',
        '/diary',
        '/weather/locations',
        '/weather/summary',
        '/push/channels',
        '/push/deliveries',
      ]),
      reason: 'Reports navigation should load all reports page data. '
          'Actual paths: ${harness.api.getPaths}',
    );
    expect(find.textContaining('failed'), findsOneWidget);

    await _tapLastTextButtonNear(tester, 'failed');
    await _pumpFrames(tester, 8);

    expect(
      harness.api.postPaths,
      contains('/push/deliveries/delivery-failed/retry'),
    );
    expect(
      harness.api.getPaths.where((path) => path == '/reports'),
      hasLength(2),
    );
  });

  testWidgets('reports generation and settings login refresh async data',
      (tester) async {
    final harness = await _pumpWebApp(tester);

    await _openShellDestination(tester, AppKeys.webShellReports);
    final reportLoads =
        harness.api.getPaths.where((path) => path == '/reports').length;

    await _tapIcon(tester, Icons.auto_awesome);

    expect(harness.api.postPaths, contains('/reports/generate'));
    expect(
      harness.api.postBodies['/reports/generate']!.single['reportType'],
      'daily',
    );
    expect(
      harness.api.getPaths.where((path) => path == '/reports').length,
      reportLoads + 1,
    );

    await _tapIcon(tester, Icons.edit_note);
    expect(harness.api.postPaths, contains('/diary/generate'));
    expect(
      harness.api.getPaths.where((path) => path == '/diary').length,
      greaterThanOrEqualTo(3),
    );

    await _openShellDestination(tester, AppKeys.webShellSettings);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'http://localhost:3500/api/');
    await tester.enterText(fields.at(1), 'login-user');
    await _tapIcon(tester, Icons.save_outlined);

    expect(harness.store.baseUrl, 'http://localhost:3500/api');
    expect(harness.store.userId, 'login-user');

    final settingsLoads =
        harness.api.getPaths.where((path) => path == '/client/settings').length;
    await _tapIcon(tester, Icons.login);

    expect(harness.api.postPaths, contains('/auth/login'));
    expect(harness.api.postBodies['/auth/login']!.single['userId'],
        'login-user');
    expect(harness.store.userId, 'server-user');
    expect(harness.store.accessToken, 'token-gap4');
    expect(
      harness.api.getPaths.where((path) => path == '/client/settings').length,
      settingsLoads + 1,
    );
  });
}

Future<void> _tapLastTextButtonNear(
  WidgetTester tester,
  String nearbyText,
) async {
  await tester.ensureVisible(find.textContaining(nearbyText).first);
  await tester.tap(find.byType(TextButton).last);
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
  final api = _Gap4WebApiClient(store);

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
  final _Gap4WebApiClient api;
}

class _Gap4WebApiClient extends WebApiClient {
  _Gap4WebApiClient(super.store);

  final getPaths = <String>[];
  final getQueries = <String, List<Map<String, String?>>>{};
  final postPaths = <String>[];
  final postBodies = <String, List<Map<String, dynamic>>>{};

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
      case '/web/events':
        return {'items': <Map<String, Object?>>[]};
      case '/reports':
        return {
          'reports': [
            {
              'id': 'report-gap4',
              'title': 'Server report',
              'reportType': 'daily',
              'status': 'draft',
              'contentMarkdown': 'Gap4 report markdown',
            },
          ],
        };
      case '/diary':
        return {
          'diary': [
            {
              'id': 'diary-gap4',
              'title': 'Server diary',
              'entryDate': '2026-06-10',
              'status': 'draft',
              'contentMarkdown': 'Gap4 diary markdown',
            },
          ],
        };
      case '/weather/locations':
        return {
          'items': [
            {'id': 'weather-gap4', 'name': 'Shanghai'},
          ],
        };
      case '/weather/summary':
        return {
          'items': [
            {
              'locationName': 'Shanghai',
              'summary': 'rain later',
              'expiresAt': '2026-06-10T12:00:00.000Z',
            },
          ],
        };
      case '/push/channels':
        return {
          'items': [
            {'id': 'channel-gap4', 'name': 'alerts'},
          ],
        };
      case '/push/deliveries':
        return {
          'items': [
            {
              'id': 'delivery-failed',
              'channel': 'alerts',
              'status': 'failed',
              'lastError': 'timeout',
            },
          ],
        };
      case '/client/settings':
        return {
          'settings': [
            {
              'key': 'remote.gap4',
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
      case '/auth/login':
        return {
          'accessToken': 'token-gap4',
          'refreshToken': 'refresh-gap4',
          'user': {'id': 'server-user'},
        };
      case '/reports/generate':
      case '/diary/generate':
      case '/push/deliveries/delivery-failed/retry':
        return {'ok': true};
      default:
        return {'ok': true};
    }
  }
}
