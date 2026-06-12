import 'dart:convert';

import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/reports_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('reports API forwards report diary push and weather commands', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <_CapturedRequest>[];
    final api = ReportsApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add(_CapturedRequest.from(request));
          return http.Response('{"ok":true}', 200);
        }),
      ),
    );

    final start = DateTime.utc(2026, 6, 8, 1);
    final end = DateTime.utc(2026, 6, 9, 1);

    await api.reports(status: 'draft', limit: 7, offset: 2);
    await api.reports();
    await api.report('report 1');
    await api.generateReport(
      reportType: 'weekly',
      periodStart: start,
      periodEnd: end,
      autoConfirm: true,
    );
    await api.confirmReport('report 1');
    await api.updateReport(
      reportId: 'report 1',
      title: 'Title',
      contentMarkdown: '# Body',
      userNote: '  note  ',
    );
    await api.updateReport(reportId: 'report 1', userNote: '   ');
    await api.polishReport('report 1');
    await api.pushReport(reportId: 'report 1', channelId: 'channel-1');
    await api.pushReport(reportId: 'report 1');
    await api.pushDeliveries(status: 'failed', limit: 9);
    await api.pushDeliveries();
    await api.retryDelivery('delivery 1');
    await api.diary(status: 'draft', limit: 8, offset: 3);
    await api.diary();
    await api.generateDiary(
      date: start,
      autoConfirm: true,
      useLlm: true,
    );
    await api.updateDiary(
      diaryId: 'diary 1',
      title: 'Diary',
      contentMarkdown: 'Body',
    );
    await api.updateDiary(diaryId: 'diary 1');
    await api.confirmDiary('diary 1');
    await api.polishDiary('diary 1');
    await api.pushChannels();
    await api.upsertPushChannel(
      channelType: 'webhook',
      name: 'Daily push',
      status: 'paused',
      config: const <String, Object?>{'url': 'https://example.test'},
    );
    await api.weatherSummary();
    await api.weatherLocations();
    await api.upsertWeatherLocation(
      name: 'Shanghai',
      latitude: 31.2,
      longitude: 121.5,
      timezone: 'Asia/Shanghai',
      isDefault: false,
    );
    await api.refreshWeather('location 1');

    expect(
      requests.map((request) => '${request.method} ${request.path}').toList(),
      <String>[
        'GET /api/reports',
        'GET /api/reports',
        'GET /api/reports/report%201',
        'POST /api/reports/generate',
        'POST /api/reports/report%201/confirm',
        'PATCH /api/reports/report%201',
        'PATCH /api/reports/report%201',
        'POST /api/reports/report%201/polish',
        'POST /api/reports/report%201/push',
        'POST /api/reports/report%201/push',
        'GET /api/push/deliveries',
        'GET /api/push/deliveries',
        'POST /api/push/deliveries/delivery%201/retry',
        'GET /api/diary',
        'GET /api/diary',
        'POST /api/diary/generate',
        'PATCH /api/diary/diary%201',
        'PATCH /api/diary/diary%201',
        'POST /api/diary/diary%201/confirm',
        'POST /api/diary/diary%201/polish',
        'GET /api/push/channels',
        'POST /api/push/channels',
        'GET /api/weather/summary',
        'GET /api/weather/locations',
        'POST /api/weather/locations',
        'POST /api/weather/locations/location%201/refresh',
      ],
    );

    expect(requests[0].query, <String, String>{
      'status': 'draft',
      'limit': '7',
      'offset': '2',
    });
    expect(requests[1].query, isNot(contains('status')));
    expect(requests[3].jsonBody, <String, Object?>{
      'reportType': 'weekly',
      'periodStart': start.toIso8601String(),
      'periodEnd': end.toIso8601String(),
      'autoConfirm': true,
    });
    expect(requests[5].jsonBody, <String, Object?>{
      'title': 'Title',
      'contentMarkdown': '# Body',
      'userNote': 'note',
    });
    expect(requests[6].jsonBody, isNot(contains('userNote')));
    expect(requests[8].jsonBody, <String, Object?>{
      'channelId': 'channel-1',
    });
    expect(requests[9].jsonBody, <String, Object?>{'channelId': null});
    expect(requests[10].query, <String, String>{
      'status': 'failed',
      'limit': '9',
    });
    expect(requests[13].query, containsPair('offset', '3'));
    expect(requests[15].jsonBody, <String, Object?>{
      'date': start.toIso8601String(),
      'autoConfirm': true,
      'useLlm': true,
    });
    expect(requests[16].jsonBody, <String, Object?>{
      'title': 'Diary',
      'contentMarkdown': 'Body',
    });
    expect(requests[17].jsonBody, isEmpty);
    expect(requests[21].jsonBody['config'], <String, Object?>{
      'url': 'https://example.test',
    });
    expect(requests[24].jsonBody, <String, Object?>{
      'name': 'Shanghai',
      'latitude': 31.2,
      'longitude': 121.5,
      'timezone': 'Asia/Shanghai',
      'isDefault': false,
    });
  });
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.jsonBody,
  });

  factory _CapturedRequest.from(http.Request request) {
    return _CapturedRequest(
      method: request.method,
      path: request.url.path,
      query: request.url.queryParameters,
      jsonBody: request.body.isEmpty
          ? const <String, Object?>{}
          : Map<String, Object?>.from(
              jsonDecode(request.body) as Map<String, dynamic>,
            ),
    );
  }

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, Object?> jsonBody;
}
