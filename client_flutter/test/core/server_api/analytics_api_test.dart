import 'package:flowplanv2/core/server_api/analytics_api.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('analytics endpoints forward expected paths and query parameters',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <String>[];
    final queries = <Map<String, String>>[];
    final api = AnalyticsApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          queries.add(Map<String, String>.from(request.url.queryParameters));
          return http.Response('{"ok":true}', 200);
        }),
      ),
    );
    final start = DateTime.utc(2026, 6, 1);
    final end = DateTime.utc(2026, 6, 10);

    await api.activityHeatmap(
      start: start,
      end: end,
      bucket: 'week',
      processName: '  Code.exe  ',
      category: '  coding ',
      taskId: 42,
    );
    await api.trackerHome(date: DateTime(2026, 6, 10, 15));
    await api.activityDaySummary(date: DateTime(2026, 6, 9, 8));
    await api.rangeAnalysis(start: start, end: end, bucket: 'month');
    await api.filterOptions(start: start, end: end);
    await api.inputHeatmap(
      start: start,
      end: end,
      bucket: 'hour',
      processName: ' Terminal ',
      category: 'dev',
      eventKind: 'keyboard',
    );
    await api.activityRangeSummary(start: start, end: end);
    await api.topApps(start: start, end: end, limit: 7);
    await api.topCategories(start: start, end: end, limit: 8);
    await api.taskWorkSummary(start: start, end: end, taskId: 9, limit: 10);
    await api.activityRecords(
      start: start,
      end: end,
      processName: 'Browser',
      category: 'research',
      taskId: 11,
      limit: 12,
      offset: 13,
    );
    await api.inputEvents(
      start: start,
      end: end,
      processName: 'MouseTool',
      category: 'ops',
      eventKind: 'mouse',
      limit: 14,
      offset: 15,
    );
    await api.focusTrends(start: start, end: end);

    expect(requests, <String>[
      'GET /api/analytics/activity-heatmap',
      'GET /api/analytics/tracker-home',
      'GET /api/analytics/activity-day-summary',
      'GET /api/analytics/range-analysis',
      'GET /api/analytics/filter-options',
      'GET /api/analytics/input-heatmap',
      'GET /api/analytics/activity-range-summary',
      'GET /api/analytics/top-apps',
      'GET /api/analytics/top-categories',
      'GET /api/analytics/task-work-summary',
      'GET /api/analytics/activity-records',
      'GET /api/analytics/input-events',
      'GET /api/analytics/focus-trends',
    ]);
    expect(queries[0], <String, String>{
      'start': '2026-06-01T00:00:00.000Z',
      'end': '2026-06-10T00:00:00.000Z',
      'bucket': 'week',
      'processName': 'Code.exe',
      'category': 'coding',
      'taskId': '42',
    });
    expect(queries[1], <String, String>{'date': '2026-06-10'});
    expect(queries[2], <String, String>{'date': '2026-06-09'});
    expect(queries[3]['bucket'], 'month');
    expect(queries[5], containsPair('eventKind', 'keyboard'));
    expect(queries[7], containsPair('limit', '7'));
    expect(queries[8], containsPair('limit', '8'));
    expect(queries[9], containsPair('taskId', '9'));
    expect(queries[10], containsPair('offset', '13'));
    expect(queries[11], containsPair('offset', '15'));
    expect(queries[12]['start'], '2026-06-01T00:00:00.000Z');
  });

  test('analytics query builder omits null and blank optional filters',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final queries = <Map<String, String>>[];
    final api = AnalyticsApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          queries.add(Map<String, String>.from(request.url.queryParameters));
          return http.Response('{}', 200);
        }),
      ),
    );

    await api.trackerHome();
    await api.activityHeatmap(
      bucket: '  ',
      processName: '  ',
      category: '',
    );
    await api.inputHeatmap(eventKind: '   ');
    await api.filterOptions();

    expect(queries[0], isEmpty);
    expect(queries[1], isEmpty);
    expect(queries[2], <String, String>{'bucket': 'day'});
    expect(queries[3], isEmpty);
  });
}
